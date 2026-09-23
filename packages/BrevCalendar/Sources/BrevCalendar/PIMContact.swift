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

/// One typed contact field value — an email address or phone number with
/// the provider's label preserved verbatim (ADR-0072 person contract).
public struct PIMContactField: Sendable, Hashable, Codable {
    /// Provider label (home / work / custom), lowercased when known.
    public var label: String?
    public var value: String

    public init(label: String? = nil, value: String) {
        self.label = label
        self.value = value
    }
}

/// A labeled date on a contact — a birthday, an anniversary, or a
/// custom-typed day (ADR-0072 person contract). Year-less dates keep
/// `year` nil so a birthday without a birth year round-trips.
public struct PIMContactDate: Sendable, Hashable, Codable {
    /// Provider label (birthday / anniversary / custom), lowercased
    /// when known.
    public var label: String?
    /// The calendar year; nil for year-less dates.
    public var year: Int?
    public var month: Int
    public var day: Int

    public init(label: String? = nil, year: Int? = nil, month: Int, day: Int) {
        self.label = label
        self.year = year
        self.month = month
        self.day = day
    }

    /// The date as a `Date` in the current calendar, with a fallback
    /// year for year-less entries — for formatting and pickers only.
    public var date: Date {
        var components = DateComponents()
        components.year = year ?? 2000
        components.month = month
        components.day = day
        return Calendar.current.date(from: components) ?? Date(
            timeIntervalSince1970: 0
        )
    }

    /// Rebuilds the value from a `Date` in the current calendar,
    /// keeping the year-less flag.
    public func withDate(_ newDate: Date) -> PIMContactDate {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: newDate
        )
        var copy = self
        copy.year = year == nil ? nil : components.year
        copy.month = components.month ?? month
        copy.day = components.day ?? day
        return copy
    }
}

/// A postal address on a contact. Components stay optional — providers
/// disagree on granularity and empty parts are omitted, not zeroed.
public struct PIMContactAddress: Sendable, Hashable, Codable {
    public var label: String?
    public var street: String?
    public var city: String?
    public var region: String?
    public var postalCode: String?
    public var country: String?

    public init(
        label: String? = nil,
        street: String? = nil,
        city: String? = nil,
        region: String? = nil,
        postalCode: String? = nil,
        country: String? = nil
    ) {
        self.label = label
        self.street = street
        self.city = city
        self.region = region
        self.postalCode = postalCode
        self.country = country
    }

    /// True when every component is empty — used to drop placeholder
    /// addresses some providers emit.
    public var isEmpty: Bool {
        [street, city, region, postalCode, country]
            .allSatisfy { $0?.isEmpty != false }
    }
}

/// A provider-neutral cached contact (ADR-0072).
///
/// CardDAV sources map one address book collection to one sync scope;
/// Google contacts sync account-wide via the People connections feed and
/// carry their group memberships in `groupKeys`. `rawPayload` keeps the
/// adapter-owned representation (vCard text or People JSON) so provider
/// fields the shared model does not read survive refreshes (R4).
public struct PIMContact: Sendable, Hashable, Codable, Identifiable {
    public typealias ID = String

    /// Stable record ID: source ID plus provider item key.
    public let id: ID
    public let sourceID: PIMSource.ID
    /// The collection this record synced under. CardDAV contacts belong
    /// to their address book; Google contacts sync source-wide and leave
    /// this nil — `groupKeys` carries their memberships.
    public var collectionID: PIMCollection.ID?
    /// Provider-side item key: absolute DAV href or Google resourceName.
    public var providerItemKey: String
    /// Provider version for conflict-aware edits (ETag / Google etag).
    public var providerVersion: String?
    /// vCard UID / Google resourceName — stable identity hint.
    public var uid: String?
    public var displayName: String
    public var givenName: String?
    public var familyName: String?
    public var nickname: String?
    public var organization: String?
    public var jobTitle: String?
    public var note: String?
    public var emails: [PIMContactField]
    public var phones: [PIMContactField]
    public var addresses: [PIMContactAddress]
    /// Labeled dates (birthdays, anniversaries, custom days).
    public var dates: [PIMContactDate]
    /// Labeled URL fields (home page, blog, profiles).
    public var urls: [PIMContactField]
    /// Provider photo URL reference. Sync stores the reference only —
    /// fetching image data is a separate, later user-visible surface and
    /// never happens during sync (ADR-0072 trust boundaries).
    public var photoURL: String?
    /// Photo bytes the user picked or a CardDAV inline PHOTO carried.
    /// Persisted so a later save keeps an untouched inline photo.
    public var photoData: Data?
    /// Group membership keys: Google contactGroupResourceNames or
    /// CardDAV CATEGORIES values.
    public var groupKeys: [String]
    /// Adapter-owned provider payload for round-trip preservation.
    /// Never shown in views.
    public var rawPayload: String?
    /// Provider-reported modification time (REV / metadata.updateTime).
    public var providerUpdatedAt: Date?
    /// When Brev wrote this record into the cache.
    public var syncedAt: Date

    public init(
        id: ID,
        sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID? = nil,
        providerItemKey: String,
        providerVersion: String? = nil,
        uid: String? = nil,
        displayName: String,
        givenName: String? = nil,
        familyName: String? = nil,
        nickname: String? = nil,
        organization: String? = nil,
        jobTitle: String? = nil,
        note: String? = nil,
        emails: [PIMContactField] = [],
        phones: [PIMContactField] = [],
        addresses: [PIMContactAddress] = [],
        dates: [PIMContactDate] = [],
        urls: [PIMContactField] = [],
        photoURL: String? = nil,
        photoData: Data? = nil,
        groupKeys: [String] = [],
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
        self.displayName = displayName
        self.givenName = givenName
        self.familyName = familyName
        self.nickname = nickname
        self.organization = organization
        self.jobTitle = jobTitle
        self.note = note
        self.emails = emails
        self.phones = phones
        self.addresses = addresses
        self.dates = dates
        self.urls = urls
        self.photoURL = photoURL
        self.photoData = photoData
        self.groupKeys = groupKeys
        self.rawPayload = rawPayload
        self.providerUpdatedAt = providerUpdatedAt
        self.syncedAt = syncedAt
    }

    /// Composes the stable record ID for a provider item on a source.
    public static func makeID(
        sourceID: PIMSource.ID,
        providerItemKey: String
    ) -> ID {
        "\(sourceID)|\(providerItemKey)"
    }
}

public enum PIMContactStoreError: Error, Sendable {
    /// The on-disk record exists but cannot be decoded.
    case unreadableStore
}

/// Persistence for synced contacts (ADR-0072).
///
/// Stores normalized display fields plus the adapter-owned raw payload.
/// Secrets never pass through this store.
public protocol PIMContactStore: Sendable {
    /// All cached contacts for a source, in stored order.
    func contacts(for sourceID: PIMSource.ID) async throws -> [PIMContact]
    /// Replaces a source's contact set atomically. Called only after a
    /// complete sync generation committed (ADR-0072 sync rule 1).
    func saveContacts(
        _ contacts: [PIMContact],
        for sourceID: PIMSource.ID
    ) async throws
    /// Removes a source's contacts. Missing data is not an error.
    func deleteContacts(for sourceID: PIMSource.ID) async throws
}

/// JSON-file-backed PIMContactStore.
///
/// The source's contact list lives inside its cache directory owned by
/// FilePIMSourceLocalDataStore, so the ADR-0072 removal contract applies
/// without extra wiring.
public actor JSONPIMContactStore: PIMContactStore {
    private let localDataStore: FilePIMSourceLocalDataStore
    private var cache: [PIMSource.ID: [PIMContact]] = [:]

    /// - Parameter localDataStore: The per-source local-data layout owner.
    public init(localDataStore: FilePIMSourceLocalDataStore) {
        self.localDataStore = localDataStore
    }

    public func contacts(for sourceID: PIMSource.ID) async throws -> [PIMContact] {
        try load(for: sourceID)
    }

    public func saveContacts(
        _ contacts: [PIMContact],
        for sourceID: PIMSource.ID
    ) async throws {
        let url = fileURL(for: sourceID)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.pimContactStore.encode(contacts)
        try data.write(to: url, options: .atomic)
        cache[sourceID] = contacts
    }

    public func deleteContacts(for sourceID: PIMSource.ID) async throws {
        let url = fileURL(for: sourceID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        cache[sourceID] = nil
    }

    /// The contacts file location inside the source's cache directory.
    public func fileURL(for sourceID: PIMSource.ID) -> URL {
        localDataStore
            .cacheDirectory(for: sourceID)
            .appendingPathComponent("contacts.json")
    }

    private func load(for sourceID: PIMSource.ID) throws -> [PIMContact] {
        if let cached = cache[sourceID] { return cached }
        let url = fileURL(for: sourceID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            cache[sourceID] = []
            return []
        }
        let data = try Data(contentsOf: url)
        guard let records = try? JSONDecoder.pimContactStore.decode(
            [PIMContact].self,
            from: data
        ) else {
            throw PIMContactStoreError.unreadableStore
        }
        cache[sourceID] = records
        return records
    }
}

/// An adapter-owned sync checkpoint for one collection — or for the
/// whole source when the provider syncs account-wide (Google People
/// connections). The token is opaque: a Google `nextSyncToken` or a DAV
/// `sync-token`. Cursors live in the source's cursor directory, which
/// FilePIMSourceLocalDataStore always wipes on removal.
public struct PIMContactSyncCursor: Sendable, Hashable, Codable {
    /// The sync scope: a collection ID, or the source ID itself for
    /// account-wide syncs.
    public let scope: String
    /// Opaque provider token; nil means the next sync is a full listing.
    public var token: String?
    /// When the generation this cursor checkpoints completed.
    public var completedAt: Date

    public init(scope: String, token: String?, completedAt: Date = Date()) {
        self.scope = scope
        self.token = token
        self.completedAt = completedAt
    }
}

/// Persistence for contact sync cursors (ADR-0072).
public protocol PIMContactSyncCursorStore: Sendable {
    /// The committed cursor for a sync scope, if any.
    func cursor(
        for sourceID: PIMSource.ID,
        scope: String
    ) async throws -> PIMContactSyncCursor?
    /// Commits a cursor after its complete generation was saved.
    func saveCursor(
        _ cursor: PIMContactSyncCursor,
        for sourceID: PIMSource.ID
    ) async throws
    /// Removes a scope's cursor. Missing data is not an error.
    func deleteCursor(
        for sourceID: PIMSource.ID,
        scope: String
    ) async throws
}

/// JSON-file-backed PIMContactSyncCursorStore inside the source's cursor
/// directory (ADR-0072 removal contract).
public actor JSONPIMContactSyncCursorStore: PIMContactSyncCursorStore {
    private let localDataStore: FilePIMSourceLocalDataStore

    /// - Parameter localDataStore: The per-source local-data layout owner.
    public init(localDataStore: FilePIMSourceLocalDataStore) {
        self.localDataStore = localDataStore
    }

    public func cursor(
        for sourceID: PIMSource.ID,
        scope: String
    ) async throws -> PIMContactSyncCursor? {
        let url = fileURL(for: sourceID, scope: scope)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try? JSONDecoder.pimContactStore.decode(
            PIMContactSyncCursor.self,
            from: data
        )
    }

    public func saveCursor(
        _ cursor: PIMContactSyncCursor,
        for sourceID: PIMSource.ID
    ) async throws {
        let url = fileURL(for: sourceID, scope: cursor.scope)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.pimContactStore.encode(cursor)
        try data.write(to: url, options: .atomic)
    }

    public func deleteCursor(
        for sourceID: PIMSource.ID,
        scope: String
    ) async throws {
        let url = fileURL(for: sourceID, scope: scope)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// The cursor file location inside the source's cursor directory.
    public func fileURL(
        for sourceID: PIMSource.ID,
        scope: String
    ) -> URL {
        localDataStore
            .cursorDirectory(for: sourceID)
            .appendingPathComponent(
                "\(Self.fileName(for: scope))-contacts.json"
            )
    }

    /// Filesystem-safe deterministic name for a sync scope.
    static func fileName(for scope: String) -> String {
        Data(scope.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension JSONEncoder {
    static let pimContactStore: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

private extension JSONDecoder {
    static let pimContactStore: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
