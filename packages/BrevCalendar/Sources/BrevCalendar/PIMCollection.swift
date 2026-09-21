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

/// A provider-neutral calendar or contacts collection on a PIM source
/// (ADR-0072). One source owns many collections: calendars for CalDAV and
/// Google Calendar sources, address books or contact groups for CardDAV
/// and Google sources. The record carries only metadata plus the user's
/// visibility choice — item sync builds on it in later slices.
public struct PIMCollection: Sendable, Hashable, Codable, Identifiable {
    public typealias ID = String

    /// Stable record ID: source ID plus provider key. If the provider
    /// deletes and re-adds a collection under a new key, the record does
    /// not pretend continuity the provider does not offer.
    public let id: ID
    public let sourceID: PIMSource.ID
    public var kind: PIMSourceKind
    public var displayName: String
    /// Provider-reported color as a hex string, when offered.
    public var colorHex: String?
    /// The credential cannot write items into this collection.
    public var isReadOnly: Bool
    /// The provider's default collection for the source.
    public var isPrimary: Bool
    /// The provider advertises token-based incremental sync for it.
    public var supportsSyncToken: Bool
    /// Stable provider-side key: absolute DAV href or Google resource ID.
    public var providerKey: String
    /// Provider version hint (CTag or ETag) for cheap change detection.
    public var providerVersion: String?
    /// Whether the collection participates in sync and browsing. A user
    /// choice preserved across refreshes; hidden collections stay cached
    /// but leave browsing surfaces.
    public var isVisible: Bool
    public var updatedAt: Date

    public init(
        id: ID,
        sourceID: PIMSource.ID,
        kind: PIMSourceKind,
        displayName: String,
        colorHex: String? = nil,
        isReadOnly: Bool = false,
        isPrimary: Bool = false,
        supportsSyncToken: Bool = false,
        providerKey: String,
        providerVersion: String? = nil,
        isVisible: Bool = true,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sourceID = sourceID
        self.kind = kind
        self.displayName = displayName
        self.colorHex = colorHex
        self.isReadOnly = isReadOnly
        self.isPrimary = isPrimary
        self.supportsSyncToken = supportsSyncToken
        self.providerKey = providerKey
        self.providerVersion = providerVersion
        self.isVisible = isVisible
        self.updatedAt = updatedAt
    }

    /// Composes the stable record ID for a provider key on a source.
    public static func makeID(
        sourceID: PIMSource.ID,
        providerKey: String
    ) -> ID {
        "\(sourceID)|\(providerKey)"
    }
}

/// What a provider adapter learned about one collection during discovery.
/// The service maps these into PIMCollection records, preserving user
/// choices (visibility) across refreshes.
public struct PIMDiscoveredCollection: Sendable, Hashable {
    /// Stable provider-side key: absolute DAV href or Google resource ID.
    public let providerKey: String
    public let displayName: String
    public let colorHex: String?
    public let isReadOnly: Bool
    public let isPrimary: Bool
    public let supportsSyncToken: Bool
    public let providerVersion: String?
    /// Provider-reported hidden/unsubscribed state. Applied only as the
    /// initial visibility for collections the user has never toggled.
    public let initiallyHidden: Bool

    public init(
        providerKey: String,
        displayName: String,
        colorHex: String? = nil,
        isReadOnly: Bool = false,
        isPrimary: Bool = false,
        supportsSyncToken: Bool = false,
        providerVersion: String? = nil,
        initiallyHidden: Bool = false
    ) {
        self.providerKey = providerKey
        self.displayName = displayName
        self.colorHex = colorHex
        self.isReadOnly = isReadOnly
        self.isPrimary = isPrimary
        self.supportsSyncToken = supportsSyncToken
        self.providerVersion = providerVersion
        self.initiallyHidden = initiallyHidden
    }
}

public enum PIMCollectionStoreError: Error, Sendable {
    /// The on-disk record exists but cannot be decoded.
    case unreadableStore
}

/// Persistence for discovered collections (ADR-0072).
///
/// Stores metadata only — names, colors, capability hints and the user's
/// visibility choice. Secrets never pass through this store.
public protocol PIMCollectionStore: Sendable {
    /// All cached collections for a source, in stored order.
    func collections(for sourceID: PIMSource.ID) async throws -> [PIMCollection]
    /// Replaces the collection set for a source atomically.
    func saveCollections(
        _ collections: [PIMCollection],
        for sourceID: PIMSource.ID
    ) async throws
    /// Removes the collection set for a source. Missing data is not an
    /// error.
    func deleteCollections(for sourceID: PIMSource.ID) async throws
}

/// JSON-file-backed PIMCollectionStore.
///
/// Each source's collection list lives inside the source's cache
/// directory owned by FilePIMSourceLocalDataStore, so the ADR-0072
/// removal contract applies without extra wiring: a kept cache keeps its
/// collection list (marked disconnected), a deleted cache loses it.
public actor JSONPIMCollectionStore: PIMCollectionStore {
    private let localDataStore: FilePIMSourceLocalDataStore
    private var cache: [PIMSource.ID: [PIMCollection]] = [:]

    /// - Parameter localDataStore: The per-source local-data layout owner.
    public init(localDataStore: FilePIMSourceLocalDataStore) {
        self.localDataStore = localDataStore
    }

    public func collections(for sourceID: PIMSource.ID) async throws -> [PIMCollection] {
        try load(for: sourceID)
    }

    public func saveCollections(
        _ collections: [PIMCollection],
        for sourceID: PIMSource.ID
    ) async throws {
        let url = fileURL(for: sourceID)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.pimCollectionStore.encode(collections)
        try data.write(to: url, options: .atomic)
        cache[sourceID] = collections
    }

    public func deleteCollections(for sourceID: PIMSource.ID) async throws {
        let url = fileURL(for: sourceID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        cache[sourceID] = nil
    }

    /// The collections file location inside the source's cache directory.
    public func fileURL(for sourceID: PIMSource.ID) -> URL {
        localDataStore
            .cacheDirectory(for: sourceID)
            .appendingPathComponent("collections.json")
    }

    private func load(for sourceID: PIMSource.ID) throws -> [PIMCollection] {
        if let cached = cache[sourceID] { return cached }
        let url = fileURL(for: sourceID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            cache[sourceID] = []
            return []
        }
        let data = try Data(contentsOf: url)
        guard let records = try? JSONDecoder.pimCollectionStore.decode(
            [PIMCollection].self,
            from: data
        ) else {
            throw PIMCollectionStoreError.unreadableStore
        }
        cache[sourceID] = records
        return records
    }
}

private extension JSONEncoder {
    static let pimCollectionStore: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

private extension JSONDecoder {
    static let pimCollectionStore: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
