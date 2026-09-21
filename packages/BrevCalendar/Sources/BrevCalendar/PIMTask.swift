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

/// Lifecycle status shared by Google Tasks (`status`) and iCalendar
/// VTODO (`STATUS`) records (ADR-0072).
public enum PIMTaskStatus: String, Sendable, Hashable, Codable, CaseIterable {
    case needsAction
    case inProcess
    case completed
    case cancelled

    /// Maps a raw provider status token onto the shared vocabulary.
    /// Google reports needsAction/completed; VTODO adds IN-PROCESS and
    /// CANCELLED. Unknown values degrade to `needsAction` — the task
    /// still shows as open.
    public init(rawValue value: String?) {
        switch value?.lowercased() {
        case "in-process", "inprocess": self = .inProcess
        case "completed": self = .completed
        case "cancelled": self = .cancelled
        default: self = .needsAction
        }
    }
}

/// A provider-neutral cached task (ADR-0072 task contract, #12).
///
/// One record per provider item: a Google task or a VTODO component.
/// Task lists are `PIMCollection` records with kind `.tasks` — a
/// Google tasklist or a CalDAV calendar that advertises VTODO support.
/// Ordering, parent links and links are capability fields: providers
/// that do not offer them leave the values nil rather than imitating
/// them. `rawPayload` keeps the adapter-owned representation (ICS
/// text or Google JSON) so provider fields survive refreshes and later
/// edits untouched by the shared model (R4).
public struct PIMTask: Sendable, Hashable, Codable, Identifiable {
    public typealias ID = String

    /// Stable record ID: collection ID plus provider item key.
    public let id: ID
    public let sourceID: PIMSource.ID
    public let collectionID: PIMCollection.ID
    /// Provider-side item key: absolute DAV href or Google task ID.
    public var providerItemKey: String
    /// Provider version for conflict-aware edits (ETag / Google etag).
    public var providerVersion: String?
    /// iCalendar UID / Google task identity across providers.
    public var uid: String?
    public var title: String?
    public var notes: String?
    /// Due date. Google reports a date-only value; VTODO DUE may carry
    /// a time. The instant is stored, not the display form.
    public var due: Date?
    /// When the task was completed; presence implies completion.
    public var completedAt: Date?
    public var status: PIMTaskStatus
    /// Provider ordering hint: Google `position` or VTODO
    /// `X-APPLE-SORT-ORDER`. nil when the provider does not order.
    public var position: String?
    /// Parent task identity: Google `parent` task ID or VTODO
    /// `RELATED-TO;RELTYPE=PARENT` UID. nil for top-level tasks.
    public var parentKey: String?
    /// Links attached to the task: Google `links[].link` or VTODO
    /// `URL`/`ATTACH` values.
    public var links: [String]
    /// Adapter-owned provider payload for round-trip preservation.
    /// Never shown in views.
    public var rawPayload: String?
    /// Provider-reported modification time (LAST-MODIFIED / updated).
    public var providerUpdatedAt: Date?
    /// When Brev wrote this record into the cache.
    public var syncedAt: Date

    public init(
        id: ID,
        sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID,
        providerItemKey: String,
        providerVersion: String? = nil,
        uid: String? = nil,
        title: String? = nil,
        notes: String? = nil,
        due: Date? = nil,
        completedAt: Date? = nil,
        status: PIMTaskStatus = .needsAction,
        position: String? = nil,
        parentKey: String? = nil,
        links: [String] = [],
        rawPayload: String? = nil,
        providerUpdatedAt: Date? = nil,
        syncedAt: Date = Date()
    ) {
        self.id = id
        self.sourceID = sourceID
        self.collectionID = collectionID
        self.providerItemKey = providerItemKey
        self.providerVersion = providerVersion
        self.uid = uid
        self.title = title
        self.notes = notes
        self.due = due
        self.completedAt = completedAt
        self.status = status
        self.position = position
        self.parentKey = parentKey
        self.links = links
        self.rawPayload = rawPayload
        self.providerUpdatedAt = providerUpdatedAt
        self.syncedAt = syncedAt
    }

    /// Composes the stable record ID for a provider item key.
    public static func makeID(
        collectionID: PIMCollection.ID,
        providerItemKey: String
    ) -> ID {
        "\(collectionID)|\(providerItemKey)"
    }

    /// True when the task is done: completed or cancelled.
    public var isCompleted: Bool {
        status == .completed || status == .cancelled || completedAt != nil
    }
}

/// Persistence for the cached task set of a task source (ADR-0072).
public protocol PIMTaskStore: Sendable {
    /// Cached tasks for one collection, in stored order.
    func tasks(
        for sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID
    ) async throws -> [PIMTask]
    /// Cached tasks across every collection of a source.
    func tasks(for sourceID: PIMSource.ID) async throws -> [PIMTask]
    /// Replaces one collection's task set atomically. Called only after
    /// a complete sync generation committed (ADR-0072 sync rule 1).
    func saveTasks(
        _ tasks: [PIMTask],
        for sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID
    ) async throws
    /// Removes one collection's tasks. Missing data is not an error.
    func deleteTasks(
        for sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID
    ) async throws
}

/// Task cache failures that are not source-setup errors.
public enum PIMTaskStoreError: Error, Sendable {
    /// The on-disk cache file could not be decoded.
    case unreadableStore
}

/// JSON-file-backed PIMTaskStore.
///
/// Each collection's tasks live in a file inside the source's cache
/// directory owned by FilePIMSourceLocalDataStore, so the ADR-0072
/// removal contract applies without extra wiring.
public actor JSONPIMTaskStore: PIMTaskStore {
    private let localDataStore: FilePIMSourceLocalDataStore
    private var cache: [String: [PIMTask]] = [:]

    /// - Parameter localDataStore: The per-source local-data layout owner.
    public init(localDataStore: FilePIMSourceLocalDataStore) {
        self.localDataStore = localDataStore
    }

    public func tasks(
        for sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID
    ) async throws -> [PIMTask] {
        try load(sourceID: sourceID, collectionID: collectionID)
    }

    public func tasks(for sourceID: PIMSource.ID) async throws -> [PIMTask] {
        let directory = tasksDirectory(for: sourceID)
        guard let names = try? FileManager.default.contentsOfDirectory(
            atPath: directory.path
        ) else { return [] }
        var all: [PIMTask] = []
        for name in names where name.hasSuffix(".json") {
            let data = try Data(contentsOf: directory.appendingPathComponent(name))
            guard let records = try? JSONDecoder.pimTaskStore.decode(
                [PIMTask].self,
                from: data
            ) else {
                throw PIMTaskStoreError.unreadableStore
            }
            all.append(contentsOf: records)
        }
        return all
    }

    public func saveTasks(
        _ tasks: [PIMTask],
        for sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID
    ) async throws {
        let url = fileURL(for: sourceID, collectionID: collectionID)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.pimTaskStore.encode(tasks)
        try data.write(to: url, options: .atomic)
        cache[cacheKey(sourceID: sourceID, collectionID: collectionID)] = tasks
    }

    public func deleteTasks(
        for sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID
    ) async throws {
        let url = fileURL(for: sourceID, collectionID: collectionID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        cache[cacheKey(sourceID: sourceID, collectionID: collectionID)] = nil
    }

    /// The tasks file location inside the source's cache directory.
    public func fileURL(
        for sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID
    ) -> URL {
        tasksDirectory(for: sourceID)
            .appendingPathComponent("\(Self.fileName(for: collectionID)).json")
    }

    private func tasksDirectory(for sourceID: PIMSource.ID) -> URL {
        localDataStore
            .cacheDirectory(for: sourceID)
            .appendingPathComponent("tasks", isDirectory: true)
    }

    /// Filesystem-safe deterministic name for a collection ID. Base64-url
    /// encoding keeps arbitrary provider keys collision-free.
    static func fileName(for collectionID: PIMCollection.ID) -> String {
        Data(collectionID.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func cacheKey(
        sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID
    ) -> String {
        "\(sourceID)|\(collectionID)"
    }

    private func load(
        sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID
    ) throws -> [PIMTask] {
        let key = cacheKey(sourceID: sourceID, collectionID: collectionID)
        if let cached = cache[key] { return cached }
        let url = fileURL(for: sourceID, collectionID: collectionID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            cache[key] = []
            return []
        }
        let data = try Data(contentsOf: url)
        guard let records = try? JSONDecoder.pimTaskStore.decode(
            [PIMTask].self,
            from: data
        ) else {
            throw PIMTaskStoreError.unreadableStore
        }
        cache[key] = records
        return records
    }
}

private extension JSONEncoder {
    static let pimTaskStore: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

private extension JSONDecoder {
    static let pimTaskStore: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
